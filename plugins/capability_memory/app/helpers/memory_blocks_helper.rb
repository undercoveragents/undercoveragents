# frozen_string_literal: true

module MemoryBlocksHelper
  def memory_block_usage_percentage(block)
    return 0 if block.char_limit.zero?

    [(block.default_value.to_s.length.to_f / block.char_limit * 100).round, 100].min
  end

  def memory_block_usage_color_class(block)
    pct = memory_block_usage_percentage(block)
    if pct >= 90 then "text-danger-500"
    elsif pct >= 70 then "text-warning-500"
    else "text-success-500"
    end
  end

  def memory_block_usage_bar_class(block)
    pct = memory_block_usage_percentage(block)
    if pct >= 90 then "bg-danger-500"
    elsif pct >= 70 then "bg-warning-500"
    else "bg-success-500"
    end
  end
end
