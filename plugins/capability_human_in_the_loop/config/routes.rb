# frozen_string_literal: true

resources :human_in_the_loop_tool_calls, only: [], path: "human_in_the_loop/tool_calls" do
  member do
    post :submit
  end
end
