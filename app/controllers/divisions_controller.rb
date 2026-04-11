# frozen_string_literal: true

class DivisionsController < ApplicationController
  before_action :authorize_platform_admin!
  before_action :load_division, only: %i[edit update archive restore impersonate]
  authorize_resource class: 'Account', instance_name: :division

  def index
    @divisions = Account.order(:name).includes(:users)
  end

  def new
    @division = Account.new(locale: 'en-US', timezone: 'UTC')
  end

  def create
    @division = Account.new(division_params)

    ApplicationRecord.transaction do
      @division.save!
      save_branding(@division)
      attach_logo(@division)

      admin = @division.users.new(admin_params.to_h.merge(password: SecureRandom.hex, role: User::ADMIN_ROLE))
      admin.save!
      admin.account_accesses.find_or_create_by!(account: @division) do |access|
        access.role = AccountAccess::ACCOUNT_ADMIN_ROLE
      end
      UserMailer.invitation_email(admin, account: @division).deliver_later!
    end

    redirect_to settings_divisions_path, notice: I18n.t('division_has_been_created')
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_content
  end

  def edit; end

  def update
    ApplicationRecord.transaction do
      @division.update!(division_params)
      save_branding(@division)
      attach_logo(@division)
    end

    redirect_to settings_divisions_path, notice: I18n.t('division_has_been_updated')
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  end

  def archive
    @division.update!(archived_at: Time.current)
    redirect_to settings_divisions_path, notice: I18n.t('division_has_been_archived')
  end

  def restore
    @division.update!(archived_at: nil)
    redirect_to settings_divisions_path, notice: I18n.t('division_has_been_restored')
  end

  def impersonate
    admin = @division.active_users.find_by(role: User::ADMIN_ROLE)
    return redirect_to settings_divisions_path, alert: I18n.t('division_does_not_have_an_active_admin') unless admin

    impersonate_user(admin)
    redirect_to root_path, notice: I18n.t('now_supporting_division_name', name: @division.name)
  end

  private

  def authorize_platform_admin!
    redirect_to root_path, alert: I18n.t('you_are_not_authorized_to_manage_divisions') unless current_user&.platform_admin?
  end

  def load_division
    @division = Account.find(params[:id])
  end

  def division_params
    params.require(:account).permit(:name, :timezone, :locale)
  end

  def admin_params
    params.require(:division_admin).permit(:email, :first_name, :last_name)
  end

  def branding_params
    return {} unless params[:branding].present?

    params.require(:branding).permit(:display_name, :support_email, :sender_name, :default_reply_to,
                                     :primary_color, :secondary_color).to_h.compact_blank
  end

  def save_branding(account)
    config = account.account_configs.find_or_initialize_by(key: AccountConfig::BRANDING_SETTINGS_KEY)
    config.value = config.value.to_h.merge(branding_params)
    config.save!
  end

  def attach_logo(account)
    return unless params.dig(:branding, :logo).present?

    account.logo.attach(params.dig(:branding, :logo))
  end
end
