# frozen_string_literal: true

class ProfileController < ApplicationController
  before_action do
    authorize!(:manage, current_user)
  end

  def show
    render :index
  end

  def update_contact
    if current_user.update(contact_params)
      if current_user.try(:pending_reconfirmation?) && current_user.previous_changes.key?(:unconfirmed_email)
        SendConfirmationInstructionsJob.perform_async('user_id' => current_user.id)

        redirect_to profile_path,
                    notice: I18n.t('a_confirmation_email_has_been_sent_to_the_new_email_address')
      else
        redirect_to profile_path, notice: I18n.t('contact_information_has_been_update')
      end
    else
      render :index, status: :unprocessable_content
    end
  end

  def update_password
    if current_user.update_with_password(password_params)
      bypass_sign_in(current_user)
      redirect_to profile_path, notice: I18n.t('password_has_been_changed')
    else
      render :index, status: :unprocessable_content
    end
  end

  def unlink_google
    if current_user.force_sso_membership_accounts.any?
      redirect_to profile_path, alert: 'Google Workspace cannot be unlinked while you still belong to a force-SSO account.'
      return
    end

    current_user.update!(provider: nil, uid: nil)

    redirect_to profile_path, notice: 'Google Workspace has been unlinked from your profile.'
  end

  private

  def contact_params
    params.require(:user).permit(:first_name, :last_name, :email)
  end

  def password_params
    params.require(:user).permit(:password, :password_confirmation, :current_password)
  end
end
