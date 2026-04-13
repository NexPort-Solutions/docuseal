# frozen_string_literal: true

class SetupController < ApplicationController
  skip_before_action :maybe_redirect_to_setup
  skip_before_action :authenticate_user!
  skip_authorization_check

  before_action :redirect_to_root_if_signed, if: :signed_in?
  before_action :ensure_first_user_not_created!

  def index
    @account = Account.new(account_params)
    @user = @account.users.new(user_params)
    @encrypted_config = GlobalEncryptedConfig.new(key: GlobalEncryptedConfig::APP_URL_KEY)
  end

  def create
    @account = Account.new(account_params)
    @account.timezone = Accounts.normalize_timezone(@account.timezone)
    @user = @account.users.new(user_params)
    @encrypted_config = GlobalEncryptedConfig.new(encrypted_config_params.merge(key: GlobalEncryptedConfig::APP_URL_KEY))

    unless URI.parse(encrypted_config_params[:value].to_s).class.in?([URI::HTTP, URI::HTTPS])
      @encrypted_config.errors.add(:value, I18n.t('should_be_a_valid_url'))

      return render :index, status: :unprocessable_content
    end

    return render :index, status: :unprocessable_content unless @account.valid?

    if @user.save
      GlobalEncryptedConfig.find_or_create_by!(key: GlobalEncryptedConfig::APP_URL_KEY) do |config|
        config.value = encrypted_config_params[:value]
      end
      GlobalEncryptedConfig.find_or_create_by!(key: GlobalEncryptedConfig::ESIGN_CERTS_KEY) do |config|
        config.value = GenerateCertificate.call.transform_values(&:to_pem)
      end
      @account.account_configs.create!(key: :fulltext_search, value: true) if SearchEntry.table_exists?

      Docuseal.refresh_default_url_options!

      sign_in(@user)

      redirect_to newsletter_path
    else
      render :index, status: :unprocessable_content
    end
  end

  private

  def user_params
    return {} unless params[:user]

    params.require(:user).permit(:first_name, :last_name, :email, :password)
  end

  def account_params
    return {} unless params[:account]

    params.require(:account).permit(:name, :timezone, :locale)
  end

  def encrypted_config_params
    return {} unless params[:global_encrypted_config]

    params.require(:global_encrypted_config).permit(:value)
  end

  def redirect_to_root_if_signed
    redirect_to root_path, notice: I18n.t('you_are_already_signed_in')
  end

  def ensure_first_user_not_created!
    redirect_to new_user_session_path, notice: I18n.t('please_sign_in') if User.exists?
  end
end
