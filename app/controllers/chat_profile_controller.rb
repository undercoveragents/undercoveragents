# frozen_string_literal: true

class ChatProfileController < ApplicationController
  layout "chat"

  def show
    @user = current_user
    @pagy_chats, @chats = pagy(:countless, Chat.user.for_user(current_user).recent, limit: 20)
  end
end
