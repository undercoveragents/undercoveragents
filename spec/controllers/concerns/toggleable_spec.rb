# frozen_string_literal: true

require "rails_helper"

RSpec.describe Toggleable do
  subject(:controller_like) do
    Class.new do
      include Toggleable
    end.new
  end

  it "requires toggle_record to be implemented" do
    expect { controller_like.send(:toggle_record) }
      .to raise_error(NotImplementedError, /toggle_record/)
  end

  it "requires toggle_redirect_path to be implemented" do
    expect { controller_like.send(:toggle_redirect_path) }
      .to raise_error(NotImplementedError, /toggle_redirect_path/)
  end

  it "requires toggle_i18n_prefix to be implemented" do
    expect { controller_like.send(:toggle_i18n_prefix) }
      .to raise_error(NotImplementedError, /toggle_i18n_prefix/)
  end
end
