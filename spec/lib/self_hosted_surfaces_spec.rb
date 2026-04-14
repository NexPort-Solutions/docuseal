# frozen_string_literal: true

require 'rails_helper'
require 'yaml'

RSpec.describe 'Self-hosted OSS surfaces' do
  it 'does not route core admin and signer surfaces to DocuSeal cloud CTAs' do
    # Arrange
    target_files = [
      Rails.root.join('app/javascript/template_builder/conditions_modal.vue'),
      Rails.root.join('app/javascript/template_builder/formula_modal.vue'),
      Rails.root.join('app/javascript/template_builder/fields.vue'),
      Rails.root.join('app/javascript/template_builder/payment_settings.vue'),
      Rails.root.join('app/javascript/submission_form/completed.vue'),
      Rails.root.join('app/javascript/submission_form/signature_step.vue'),
      Rails.root.join('app/javascript/elements/emails_textarea.js'),
      Rails.root.join('app/views/pages/landing.html.erb'),
      Rails.root.join('app/views/esign_settings/_default_signature_row.html.erb'),
      Rails.root.join('app/views/sso_settings/_placeholder.html.erb'),
      Rails.root.join('app/views/notifications_settings/_reminder_placeholder.html.erb'),
      Rails.root.join('app/views/personalization_settings/_logo_placeholder.html.erb'),
      Rails.root.join('app/views/submissions/_bulk_send_placeholder.html.erb'),
      Rails.root.join('app/views/templates_code_modal/_placeholder.html.erb')
    ]
    forbidden_fragments = [
      'https://www.docuseal.com/pricing',
      'https://www.docuseal.com/qualified-electronic-signature',
      'https://www.docuseal.com/blog/accept-payments-and-request-signatures-with-ease',
      'https://www.docuseal.com/esign-disclosure',
      'https://www.docuseal.com/install',
      'https://www.docuseal.com/start',
      'https://docuseal.com/sign_up',
      'href="/upgrade"'
    ]

    # Initial Assert
    expect(target_files).to all(exist)

    # Act
    file_contents = target_files.to_h { |path| [path.to_s, path.read] }

    # Assert
    file_contents.each do |path, content|
      forbidden_fragments.each do |fragment|
        expect(content).not_to include(fragment), "#{path} still includes #{fragment}"
      end
    end
  end

  it 'does not leave Pro-only blockers in the template conditions modal' do
    # Arrange
    modal_path = Rails.root.join('app/javascript/template_builder/conditions_modal.vue')
    forbidden_fragments = [
      "t('available_in_pro')",
      "t('available_only_in_pro')"
    ]

    # Initial Assert
    expect(modal_path).to exist

    # Act
    modal_content = modal_path.read

    # Assert
    forbidden_fragments.each do |fragment|
      expect(modal_content).not_to include(fragment), "conditions modal still includes #{fragment}"
    end
  end

  it 'keeps active locale help and legal copy self-hosted-safe' do
    # Arrange
    locale_path = Rails.root.join('config/locales/i18n.yml')

    # Initial Assert
    expect(locale_path).to exist

    # Act
    locale_data = YAML.load_file(locale_path, aliases: true)

    # Assert
    locale_data.each do |locale, strings|
      next unless strings.is_a?(Hash)

      if strings.key?('by_creating_an_account_you_agree_to_our_html')
        expect(strings.fetch('by_creating_an_account_you_agree_to_our_html')).not_to include('docuseal.com/'),
          "#{locale} legal copy still links to DocuSeal cloud"
      end

      if strings.key?('click_here_to_learn_more_about_user_roles_and_permissions_html')
        expect(strings.fetch('click_here_to_learn_more_about_user_roles_and_permissions_html')).not_to include('docuseal.com/'),
          "#{locale} roles help still links to DocuSeal cloud"
      end

      if strings.key?('your_email_could_not_be_reached_this_may_happen_if_there_was_a_typo_in_your_address_or_if_your_mailbox_is_not_available_please_contact_support_email_to_log_in')
        expect(strings.fetch('your_email_could_not_be_reached_this_may_happen_if_there_was_a_typo_in_your_address_or_if_your_mailbox_is_not_available_please_contact_support_email_to_log_in')).not_to include('support@docuseal.com'),
          "#{locale} unreachable-email copy still references support@docuseal.com"
      end

      if strings.dig('app_tour', 'support_description').present?
        expect(strings.dig('app_tour', 'support_description')).not_to include('support@docuseal.com'),
          "#{locale} app tour support copy still references support@docuseal.com"
      end
    end
  end
end
