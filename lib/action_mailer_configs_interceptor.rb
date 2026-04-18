# frozen_string_literal: true

module ActionMailerConfigsInterceptor
  OPEN_TIMEOUT = ENV.fetch('SMTP_OPEN_TIMEOUT', '15').to_i
  READ_TIMEOUT = ENV.fetch('SMTP_READ_TIMEOUT', '25').to_i
  SMTP_SETTINGS_MESSAGE_IVAR = :@docuseal_smtp_settings
  SMTP_FROM_MESSAGE_IVAR = :@docuseal_smtp_from

  module_function

  def delivering_email(message)
    return message unless Rails.env.production?

    if Docuseal.demo?
      message.delivery_method(:test)

      return message
    end

    if (smtp_settings = preferred_smtp_settings(message))
      message.delivery_method(:smtp, smtp_settings)
      apply_from_address(message, preferred_smtp_from(message))

      return message
    end

    if Docuseal.multitenant?
      if (smtp_settings = env_smtp_settings)
        message.delivery_method(:smtp, smtp_settings)
        apply_from_address(message, smtp_from_env)
      end

      return message
    end

    if (smtp_value = global_smtp_value)
      message.delivery_method(:smtp, build_smtp_configs_hash(smtp_value))
      apply_from_address(message, smtp_value['from_email'])
    elsif (smtp_settings = env_smtp_settings)
      message.delivery_method(:smtp, smtp_settings)
      apply_from_address(message, smtp_from_env)
    else
      message.delivery_method(:test)
    end

    message
  end

  def global_smtp_configured?
    global_smtp_value.present?
  end

  def env_smtp_configured?
    env_smtp_settings.present?
  end

  def global_smtp_value
    EncryptedConfigValueReader.fetch(
      GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY),
      source: 'global current',
      key: GlobalEncryptedConfig::EMAIL_SMTP_KEY
    ).value.presence
  end

  def env_smtp_settings
    return unless Rails.application.config.action_mailer.delivery_method == :smtp

    settings = Rails.application.config.action_mailer.smtp_settings.to_h.deep_dup

    return if settings.blank? || settings.values.any? { |value| unresolved_key_vault_reference?(value) }

    settings
  end

  def smtp_from_env
    [ENV['SMTP_FROM'], ENV['MAIL_FROM']]
      .filter_map { |value| normalized_env_value(value) }
      .flat_map { |value| value.split(',') }
      .map(&:strip)
      .reject(&:blank?)
      .sample
  end

  def apply_from_address(message, from)
    return if from.blank?

    current_from = message[:from]
    current_from_value = current_from.to_s
    current_email = Array.wrap(message.from).first.to_s
    current_display_name = parsed_display_name(current_from_value)

    if from.include?('<') && from.include?('>')
      message[:from] = from
    elsif current_display_name.present? && from.match?(User::EMAIL_REGEXP)
      message.from = formatted_from_address(current_display_name, from)
    elsif current_email.match?(User::EMAIL_REGEXP)
      message[:from] = current_email.sub(User::EMAIL_REGEXP, from)
    else
      message.from = from
    end
  end

  def formatted_from_address(display_name, email)
    Mail::Address.new(email).tap { |address| address.display_name = display_name }.format
  end

  def parsed_display_name(from)
    return if from.blank? || !from.include?('<')

    from.sub(/\s*<.*\z/, '').delete_prefix('"').delete_suffix('"').strip.presence
  end

  def build_smtp_configs_hash(value)
    is_tls = value['security'] == 'tls' || (value['security'].blank? && value['port'].to_s == '465')
    is_ssl = value['security'] == 'ssl'
    is_noverify = value['security'] == 'noverify'

    enable_starttls = is_noverify ? :enable_starttls_auto : :enable_starttls

    {
      user_name: value['username'],
      password: value['password'],
      address: value['host'],
      port: value['port'],
      domain: value['domain'],
      openssl_verify_mode: is_noverify ? OpenSSL::SSL::VERIFY_NONE : nil,
      authentication: value['password'].present? ? value.fetch('authentication', 'plain') : nil,
      enable_starttls => !is_tls && !is_ssl,
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT,
      ssl: is_ssl,
      tls: is_tls
    }.compact_blank
  end

  def preferred_smtp_settings(message)
    message.instance_variable_get(SMTP_SETTINGS_MESSAGE_IVAR)
  end

  def preferred_smtp_from(message)
    message.instance_variable_get(SMTP_FROM_MESSAGE_IVAR)
  end

  def normalized_env_value(value)
    return if value.blank? || unresolved_key_vault_reference?(value)

    value.to_s
  end

  def unresolved_key_vault_reference?(value)
    value.is_a?(String) && value.start_with?('@Microsoft.KeyVault(')
  end
end
