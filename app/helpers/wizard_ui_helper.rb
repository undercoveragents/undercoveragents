# frozen_string_literal: true

module WizardUiHelper
  WizardStep = Data.define(:number, :label, :target_id)
  WizardComponent = Data.define(:eyebrow, :title, :subtitle, :steps)

  def build_wizard_component(eyebrow:, title:, steps:, subtitle: nil)
    WizardComponent.new(
      eyebrow: eyebrow.to_s.presence,
      title:,
      subtitle: subtitle.to_s.presence,
      steps: build_wizard_steps(steps),
    )
  end

  def build_wizard_steps(steps)
    Array(steps).each_with_index.map do |step, index|
      attributes = step.to_h.symbolize_keys

      WizardStep.new(
        number: (attributes[:number] || (index + 1)).to_s,
        label: attributes.fetch(:label),
        target_id: attributes.fetch(:target_id),
      )
    end
  end

  def wizard_status_icon(kind)
    {
      "error" => "fa-circle-xmark",
      "info" => "fa-circle-info",
      "success" => "fa-circle-check",
    }.fetch(kind.to_s, "fa-circle-info")
  end
end
