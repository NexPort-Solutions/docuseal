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
    current_account.update!(account_params) if account_params.present?
    update_branding!
    update_home_page_content!
    attach_logo!

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
    return {} unless params[:account].present?

    params.require(:account).permit(:name, :timezone, :locale)
  end

  def branding_params
    return nil unless params[:branding].present?

    params.require(:branding).permit(:display_name, :support_email, :sender_name, :default_reply_to,
                                     :primary_color, :secondary_color).to_h.compact_blank
  end

  def update_branding!
    return if branding_params.blank?

    config = current_account.account_configs.find_or_initialize_by(key: AccountConfig::BRANDING_SETTINGS_KEY)
    config.value = config.value.to_h.merge(branding_params)
    config.save!
  end

  def update_home_page_content!
    return unless params.key?(:home_page_content)

    config = current_account.account_configs.find_or_initialize_by(key: AccountConfig::HOME_PAGE_CONTENT_KEY)
    content = params[:home_page_content].to_s.strip

    if content.blank?
      config.destroy! if config.persisted?
    else
      config.value = content
      config.save!
    end
  end

  def attach_logo!
    return unless params.dig(:branding, :logo).present?

    current_account.logo.attach(params.dig(:branding, :logo))
  end
end
