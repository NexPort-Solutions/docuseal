# frozen_string_literal: true

module Admin
  class AccountsController < BaseController
    before_action :load_account, only: %i[edit update archive restore impersonate]

    def index
      @accounts = Account.order(:name).includes(:users)
    end

    def new
      @account = Account.new(locale: 'en-US', timezone: 'UTC')
    end

    def create
      @account = Account.new(account_params)

      ApplicationRecord.transaction do
        @account.save!
        save_branding(@account)
        attach_logo(@account)

        admin = @account.users.new(account_admin_params.to_h.merge(password: SecureRandom.hex, role: User::ADMIN_ROLE))
        admin.save!
        admin.account_accesses.find_or_create_by!(account: @account) do |access|
          access.role = AccountAccess::ACCOUNT_ADMIN_ROLE
        end
        UserMailer.invitation_email(admin, account: @account).deliver_later!
      end

      redirect_to admin_accounts_path, notice: I18n.t('division_has_been_created')
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_content
    end

    def edit; end

    def update
      ApplicationRecord.transaction do
        @account.update!(account_params)
        save_branding(@account)
        attach_logo(@account)
      end

      redirect_to admin_accounts_path, notice: I18n.t('division_has_been_updated')
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    def archive
      @account.update!(archived_at: Time.current)
      redirect_to admin_accounts_path, notice: I18n.t('division_has_been_archived')
    end

    def restore
      @account.update!(archived_at: nil)
      redirect_to admin_accounts_path, notice: I18n.t('division_has_been_restored')
    end

    def impersonate
      admin = @account.active_users.find_by(role: User::ADMIN_ROLE)
      return redirect_to admin_accounts_path, alert: I18n.t('division_does_not_have_an_active_admin') unless admin

      impersonate_user(admin)
      redirect_to root_path, notice: I18n.t('now_supporting_division_name', name: @account.name)
    end

    private

    def load_account
      @account = Account.find(params[:id])
    end

    def account_params
      params.require(:account).permit(:name, :timezone, :locale)
    end

    def account_admin_params
      params.require(:account_admin).permit(:email, :first_name, :last_name)
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
end
