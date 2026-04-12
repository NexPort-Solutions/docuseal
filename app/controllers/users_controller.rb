# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :ensure_manage_current_account!
  before_action :load_user, only: %i[edit update destroy]
  before_action :build_user, only: %i[new create]

  def index
    @users =
      if params[:status] == 'archived'
        current_account.members.archived.where.not(role: 'integration')
      elsif params[:status] == 'integration'
        current_account.members.active.where(role: 'integration')
      else
        current_account.members.active.where.not(role: 'integration')
      end

    @pagy, @users = pagy(@users.preload(:account_accesses).distinct.order(id: :desc))
  end

  def new; end

  def edit; end

  def create
    existing_user = User.find_by(email: @user.email)

    if existing_user
      if existing_user.can_access_account?(current_account)
        @user.errors.add(:email, I18n.t('already_exists'))

        return render_user_form(:new)
      end

      existing_user.archived_at = nil
      @user = existing_user
    end

    @user.password = SecureRandom.hex if @user.password.blank?
    @user.role = User::ADMIN_ROLE unless role_valid?(@user.role)

    if @user.save
      upsert_membership!(@user)
      UserMailer.invitation_email(@user, account: current_account).deliver_later!

      redirect_back fallback_location: settings_users_path, notice: I18n.t('user_has_been_invited')
    else
      render_user_form(:new)
    end
  end

  def update
    return redirect_to settings_users_path, notice: I18n.t('unable_to_update_user') if Docuseal.demo?

    attrs = user_params.compact_blank
    attrs = attrs.merge(user_params.slice(:archived_at))

    if @user.update(attrs.except(*(current_user == @user ? %i[password otp_required_for_login role] : %i[password])))
      upsert_membership!(@user) if params.dig(:user, :membership_role).present?

      if @user.try(:pending_reconfirmation?) && @user.previous_changes.key?(:unconfirmed_email)
        SendConfirmationInstructionsJob.perform_async('user_id' => @user.id)

        redirect_back fallback_location: settings_users_path,
                      notice: I18n.t('a_confirmation_email_has_been_sent_to_the_new_email_address')
      else
        redirect_back fallback_location: settings_users_path, notice: I18n.t('user_has_been_updated')
      end
    else
      render_user_form(:edit)
    end
  end

  def destroy
    if Docuseal.demo? || @user.id == current_user.id
      return redirect_to settings_users_path, notice: I18n.t('unable_to_remove_user')
    end

    membership = @user.account_accesses.find_by!(account: current_account)

    if @user.account_accesses.one? && !@user.platform_admin?
      @user.update!(archived_at: Time.current)
    else
      membership.destroy!
      @user.sync_membership_state!
    end

    redirect_back fallback_location: settings_users_path, notice: I18n.t('user_has_been_removed')
  end

  private

  def role_valid?(role)
    return false unless User::ROLES.include?(role)
    return true if role != User::PLATFORM_ADMIN_ROLE

    current_user&.platform_admin?
  end

  def build_user
    @user = current_account.users.new(user_params.except(:membership_role))
  end

  def user_params
    if params.key?(:user)
      permitted_params = %i[email first_name last_name password archived_at otp_required_for_login membership_role]

      permitted_params << :role if role_valid?(params.dig(:user, :role))

      params.require(:user).permit(permitted_params)
    else
      {}
    end
  end

  def load_user
    @user = current_account.members.find(params[:id])
  end

  def ensure_manage_current_account!
    authorize!(:manage, current_account)
  end

  def render_user_form(template)
    if turbo_frame_request?
      render turbo_stream: turbo_stream.replace(:modal, template: "users/#{template}"), status: :unprocessable_content
    else
      render template, layout: false, status: :unprocessable_content
    end
  end

  def upsert_membership!(user)
    membership = user.account_accesses.find_or_initialize_by(account: current_account)
    membership.role = membership_role
    membership.save!
    user.sync_membership_state!
  end

  def membership_role
    params.dig(:user, :membership_role).presence_in(AccountAccess::ROLES) || AccountAccess::CONTRIBUTOR_ROLE
  end
end
