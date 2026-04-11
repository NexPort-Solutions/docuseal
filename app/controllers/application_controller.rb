# frozen_string_literal: true

class ApplicationController < ActionController::Base
  BROWSER_LOCALE_REGEXP = /\A\w{2}(?:-\w{2})?/

  include ActiveStorage::SetCurrent
  include Pagy::Method

  check_authorization unless: :devise_controller?

  around_action :with_locale
  before_action :sign_in_for_demo, if: -> { Docuseal.demo? }
  before_action :maybe_redirect_to_setup, unless: :signed_in?
  before_action :authenticate_user!, unless: :devise_controller?

  before_action :set_csp, if: -> { request.get? && !request.headers['HTTP_X_TURBO'] }

  helper_method :button_title,
                :accessible_accounts,
                :admin_managed_accounts,
                :current_account,
                :current_account_access,
                :true_ability,
                :branding_account,
                :branding_name,
                :branding_primary_color,
                :branding_secondary_color,
                :branding_support_email,
                :form_link_host,
                :svg_icon

  impersonates :user, with: ->(uuid) { User.find_by(uuid:) }

  rescue_from Pagy::RangeError do
    redirect_to request.path
  end

  rescue_from RateLimit::LimitApproached do |e|
    Rollbar.error(e) if defined?(Rollbar)

    redirect_to request.referer, alert: 'Too many requests', status: :too_many_requests
  end

  if Rails.env.production? || Rails.env.test?
    rescue_from CanCan::AccessDenied do |e|
      Rollbar.warning(e) if defined?(Rollbar)

      redirect_to root_path, alert: e.message
    end
  end

  def default_url_options
    Docuseal.default_url_options
  end

  def impersonate_user(user)
    raise ArgumentError unless user
    raise Pretender::Error unless true_user

    @impersonated_user = user

    request.session[:impersonated_user_id] = user.uuid
  end

  def pagy_auto(collection, **keyword_args)
    if current_ability.can?(:manage, :countless)
      pagy(:countless, collection, **keyword_args)
    else
      pagy(collection, **keyword_args)
    end
  end

  private

  def with_locale(&)
    return yield unless current_account

    locale   = params[:lang].presence if Rails.env.development?
    locale ||= current_account.locale

    I18n.with_locale(locale, &)
  end

  def with_browser_locale(&)
    return yield if I18n.locale != :'en-US' && I18n.locale != :en

    locale   = params[:lang].presence
    locale ||= request.env['HTTP_ACCEPT_LANGUAGE'].to_s[BROWSER_LOCALE_REGEXP].to_s

    locale =
      if locale.starts_with?('en-') && locale != 'en-US'
        'en-GB'
      else
        locale.split('-').first.presence || 'en-GB'
      end

    locale = 'en-GB' unless I18n.locale_available?(locale)

    I18n.with_locale(locale, &)
  end

  def sign_in_for_demo
    sign_in(User.active.order('random()').take) unless signed_in?
  end

  def current_account
    return unless current_user

    @current_account ||= resolve_current_account
  end

  def current_account_access
    return unless current_user && current_account

    @current_account_access ||= current_user.account_access_for(current_account)
  end

  def current_ability
    @current_ability ||= Ability.new(current_user, current_account:)
  end

  def accessible_accounts
    return Account.none unless current_user

    @accessible_accounts ||= current_user.accessible_accounts
  end

  def admin_managed_accounts
    return Account.none unless current_user

    @admin_managed_accounts ||= current_user.admin_managed_accounts
  end

  def branding_account
    return current_account if current_account
    return @account if defined?(@account) && @account.present?
    return @division if defined?(@division) && @division.present?
    return @submitter.account if defined?(@submitter) && @submitter.present?
    return @submission.account if defined?(@submission) && @submission.present?
    return @template.account if defined?(@template) && @template.present?

    account_id = params[:account_id].presence || params[:division_id].presence

    Account.find_by(id: account_id) if account_id.present?
  end

  def branding_name
    branding_account&.branded_name || Docuseal.product_name
  end

  def branding_primary_color
    branding_account&.primary_color || Docuseal::DEFAULT_PRIMARY_COLOR
  end

  def branding_secondary_color
    branding_account&.secondary_color || Docuseal::DEFAULT_SECONDARY_COLOR
  end

  def branding_support_email
    branding_account&.support_email || Docuseal::SUPPORT_EMAIL
  end

  def true_ability
    @true_ability ||= Ability.new(true_user, current_account:)
  end

  def maybe_redirect_to_setup
    redirect_to setup_index_path unless User.exists?
  end

  def select_current_account!(account)
    raise CanCan::AccessDenied unless current_user&.can_access_account?(account)

    session[:selected_account_id] = account.id
    current_user.update_column(:account_id, account.id) if current_user.account_id != account.id
    current_user.account = account
    @current_account = account
    @current_account_access = nil
    @current_ability = nil
  end

  def button_title(title: I18n.t('submit'), disabled_with: I18n.t('submitting'), title_class: '', icon: nil,
                   icon_disabled: nil)
    render_to_string(partial: 'shared/button_title',
                     locals: { title:, disabled_with:, title_class:, icon:, icon_disabled: })
  end

  def svg_icon(icon_name, class: '')
    render_to_string(partial: "icons/#{icon_name}", locals: { class: })
  end

  def form_link_host
    Docuseal.default_url_options[:host]
  end

  def maybe_redirect_com
    return if request.domain != 'docuseal.co'

    redirect_to request.url.gsub('.co/', '.com/'), allow_other_host: true, status: :moved_permanently
  end

  def set_csp
    request.content_security_policy = current_content_security_policy.tap do |policy|
      policy.default_src :self
      policy.script_src :self
      policy.style_src :self, :unsafe_inline
      policy.img_src :self, :https, :http, :blob, :data
      policy.font_src :self, :https, :http, :blob, :data
      policy.manifest_src :self
      policy.media_src :self
      policy.frame_src :self
      policy.worker_src :self, :blob
      policy.connect_src :self

      policy.directives['connect-src'] << 'ws:' if Rails.env.development?
    end
  end

  def resolve_current_account
    if current_user.platform_admin?
      Account.active.find_by(id: selected_account_id) ||
        Account.active.find_by(id: current_user.account_id) ||
        Account.active.order(:name).first
    else
      current_user.accessible_accounts.find_by(id: selected_account_id) ||
        current_user.accessible_accounts.find_by(id: current_user.account_id) ||
        current_user.accessible_accounts.first
    end
  end

  def selected_account_id
    session[:selected_account_id].presence
  end
end
