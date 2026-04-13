# frozen_string_literal: true

class MembersController < ApplicationController
  before_action :authorize_members_management!
  before_action :load_member, only: %i[edit update destroy]

  def index
    @pagy, @members =
      pagy(current_account.members.active.where.not(role: 'integration').preload(:account_accesses).distinct.order(id: :desc))
  end

  def edit; end

  def update
    membership = @member.account_accesses.find_by!(account: current_account)
    membership.update!(role: membership_role)

    redirect_to settings_users_path, notice: I18n.t('user_has_been_updated')
  rescue ActiveRecord::RecordInvalid
    render_member_form(:edit)
  end

  def destroy
    return redirect_to settings_users_path, notice: I18n.t('unable_to_remove_user') if Docuseal.demo? || @member == current_user

    membership = @member.account_accesses.find_by!(account: current_account)
    membership.destroy!
    @member.sync_membership_state!

    redirect_to settings_users_path, notice: I18n.t('user_has_been_removed')
  end

  private

  def authorize_members_management!
    authorize!(:manage_members, current_account)
  end

  def load_member
    @member = current_account.members.find(params[:id])
  end

  def membership_role
    params.dig(:member, :membership_role).presence_in(AccountAccess::ROLES) || AccountAccess::CONTRIBUTOR_ROLE
  end

  def render_member_form(template)
    if turbo_frame_request?
      render turbo_stream: turbo_stream.replace(:modal, template: "members/#{template}"), status: :unprocessable_content
    else
      render template, layout: false, status: :unprocessable_content
    end
  end
end
