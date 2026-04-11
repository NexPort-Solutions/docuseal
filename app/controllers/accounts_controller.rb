# frozen_string_literal: true

class AccountsController < ApplicationController
  LOCALE_OPTIONS = {
    'en-US' => 'English (United States)',
    'en-GB' => 'English (United Kingdom)',
    'fr-FR' => 'Français',
    'es-ES' => 'Español',
    'pt-PT' => 'Português',
    'de-DE' => 'Deutsch',
    'it-IT' => 'Italiano',
    'nl-NL' => 'Nederlands'
  }.freeze

  before_action :load_account
  authorize_resource :account

  def show; end

  def update
    load_app_url_config

    if @encrypted_config.present? && !valid_http_url?(@encrypted_config.value.to_s)
      @encrypted_config.errors.add(:value, I18n.t('should_be_a_valid_url'))

      return render :show, status: :unprocessable_content
    end

    current_account.update!(account_params)
    update_branding!
    attach_logo!
    @encrypted_config&.save!
    Docuseal.refresh_default_url_options! if @encrypted_config.present?

    with_locale do
      redirect_to settings_account_path, notice: I18n.t('account_information_has_been_updated')
    end
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_content
  end

  def destroy
    authorize!(:manage, current_account)
    raise CanCan::AccessDenied unless Docuseal.multitenant? && true_user == current_user

    true_user.skip_reconfirmation!
    true_user.update!(locked_at: Time.current, email: true_user.email.sub('@', '+removed@'))
    true_user.account.update!(archived_at: Time.current)

    # rubocop:disable Layout/LineLength
    render turbo_stream: turbo_stream.replace(
      :account_delete_button,
      html: helpers.tag.p(I18n.t('your_account_removal_request_will_be_processed_within_2_months_please_contact_us_if_you_want_to_keep_your_account'))
    )
    # rubocop:enable Layout/LineLength
  end

  private

  def load_account
    @account = current_account
  end

  def account_params
    params.require(:account).permit(:name, :timezone, :locale)
  end

  def app_url_params
    return {} if params[:encrypted_config].blank?

    params.require(:encrypted_config).permit(:value)
  end

  def load_app_url_config
    return if Docuseal.multitenant? || app_url_params.blank?

    @encrypted_config = EncryptedConfig.find_or_initialize_by(account: current_account,
                                                              key: EncryptedConfig::APP_URL_KEY)
    @encrypted_config.assign_attributes(app_url_params)
  end

  def valid_http_url?(value)
    URI.parse(value).class.in?([URI::HTTP, URI::HTTPS])
  rescue URI::InvalidURIError
    false
  end

  def branding_params
    return {} unless params[:branding].present?

    params.require(:branding).permit(:display_name, :support_email, :sender_name, :default_reply_to,
                                     :primary_color, :secondary_color).to_h.compact_blank
  end

  def update_branding!
    config = current_account.account_configs.find_or_initialize_by(key: AccountConfig::BRANDING_SETTINGS_KEY)
    config.value = config.value.to_h.merge(branding_params)
    config.save!
  end

  def attach_logo!
    return unless params.dig(:branding, :logo).present?

    current_account.logo.attach(params.dig(:branding, :logo))
  end
end
