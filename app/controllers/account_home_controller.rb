# frozen_string_literal: true

class AccountHomeController < ApplicationController
  skip_authorization_check

  def show
    redirect_to root_path unless current_account
  end
end
