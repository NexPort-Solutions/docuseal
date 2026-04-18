# frozen_string_literal: true

module ActionMailerConfigsInterceptor
  OPEN_TIMEOUT = ENV.fetch('SMTP_OPEN_TIMEOUT', '15').to_i
  READ_TIMEOUT = ENV.fetch('SMTP_READ_TIMEOUT', '25').to_i

  module_function

  def delivering_email(message)
    return message unless Rails.env.production?

    if Docuseal.demo?
      message.delivery_method(:test)

      return message
    end

    if Rails.env.production? && Rails.application.config.action_mailer.delivery_method
      apply_from_address(message, smtp_from_env)

      return message
    end

    unless Docuseal.multitenant?
      email_configs = GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)

      if email_configs
        message.delivery_method(:smtp, build_smtp_configs_hash(email_configs))
        apply_from_address(message, email_configs.value['from_email'])
      else
        message.delivery_method(:test)
      end
    end

    message
  end

  def smtp_from_env
    (ENV['SMTP_FROM'].presence || ENV['MAIL_FROM'].presence).to_s.split(',').map(&:strip).reject(&:blank?).sample
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

  def build_smtp_configs_hash(email_configs)
    value = email_configs.value

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
end
