# frozen_string_literal: true

class EmailSmtpSettingsController < ApplicationController
  skip_authorization_check

  before_action :raise_not_found

  def index
    head :not_found
  end

  def create
    head :not_found
  end

  def raise_not_found
    return if action_name.in?(%w[index create])

    head :not_found
  end
end
