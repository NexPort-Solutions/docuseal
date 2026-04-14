# frozen_string_literal: true

module Admin
  class UsersController < BaseController
    before_action :load_user, only: %i[edit update destroy memberships]
    before_action :build_user, only: %i[new create]

    def index
      @users = User.includes(account_accesses: :account).order(id: :desc)
    end

    def new; end

    def edit; end

    def memberships
      @memberships = @user.active_account_accesses
    end

    def create
      @user.password = SecureRandom.hex if @user.password.blank?
      @user.role = normalized_role(@user.role)
      @user.account ||= primary_account_for_new_user

      ApplicationRecord.transaction do
        @user.save!
        ensure_memberships_for_create!
      end

      invite_to_first_membership!(@user)
      redirect_to admin_users_path, notice: I18n.t('user_has_been_invited')
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_content
    end

    def update
      attrs = user_params.compact_blank
      attrs = attrs.merge(user_params.slice(:archived_at))

      prevent_self_demotion_or_archive!

      ApplicationRecord.transaction do
        @user.update!(attrs.except(:memberships, :password))
        @user.update!(password: attrs[:password]) if attrs[:password].present?
        sync_memberships!(@user)
      end

      if @user.try(:pending_reconfirmation?) && @user.previous_changes.key?(:unconfirmed_email)
        SendConfirmationInstructionsJob.perform_async('user_id' => @user.id)

        redirect_to admin_users_path, notice: I18n.t('a_confirmation_email_has_been_sent_to_the_new_email_address')
      else
        redirect_to admin_users_path, notice: I18n.t('user_has_been_updated')
      end
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    def destroy
      raise CanCan::AccessDenied if @user == current_user

      @user.update!(archived_at: Time.current)

      redirect_to admin_users_path, notice: I18n.t('user_has_been_removed')
    end

    private

    def build_user
      @user = User.new(user_params.except(:memberships))
    end

    def load_user
      @user = User.includes(account_accesses: :account).find(params[:id])
    end

    def user_params
      return {} unless params[:user]

      params.require(:user).permit(:email, :first_name, :last_name, :password, :archived_at, :otp_required_for_login, :role,
                                   memberships: {})
    end

    def memberships_params
      user_params.fetch(:memberships, {}).to_h
    end

    def selected_memberships
      memberships_params.filter_map do |account_id, attrs|
        attrs = attrs.to_h.symbolize_keys
        next unless ActiveModel::Type::Boolean.new.cast(attrs[:selected])

        [account_id.to_i, attrs[:role].presence_in(AccountAccess::ROLES) || AccountAccess::CONTRIBUTOR_ROLE]
      end.to_h
    end

    def ensure_memberships_for_create!
      if selected_memberships.blank? && !@user.platform_admin?
        @user.errors.add(:base, I18n.t('user_must_belong_to_at_least_one_account'))
        raise ActiveRecord::RecordInvalid, @user
      end

      sync_memberships!(@user)
    end

    def sync_memberships!(user)
      memberships = selected_memberships

      user.account_accesses.where.not(account_id: memberships.keys).destroy_all

      memberships.each do |account_id, role|
        user.account_accesses.find_or_initialize_by(account_id:).tap do |membership|
          membership.role = role
          membership.save!
        end
      end

      user.archived_at = Time.current if memberships.empty? && !user.platform_admin?
      user.archived_at = nil if memberships.present? && user.archived_at?
      user.save!(validate: false) if user.changed?
      user.sync_membership_state!
    end

    def invite_to_first_membership!(user)
      account = user.accessible_accounts.first
      return unless account

      UserMailer.invitation_email(user, account:).deliver_later!
    end

    def normalized_role(role)
      role.presence_in(User::ROLES) || User::ADMIN_ROLE
    end

    def prevent_self_demotion_or_archive!
      return unless @user == current_user
      return if (params.dig(:user, :role).blank? || params.dig(:user, :role) == User::PLATFORM_ADMIN_ROLE) &&
                params.dig(:user, :archived_at).blank?

      raise CanCan::AccessDenied
    end

    def primary_account_for_new_user
      Account.find_by(id: selected_memberships.keys.first) || current_account
    end
  end
end
