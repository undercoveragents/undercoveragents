# frozen_string_literal: true

# == Schema Information
#
# Table name: rag_runs
# Database name: primary
#
#  id            :bigint           not null, primary key
#  completed_at  :datetime
#  error_message :text
#  started_at    :datetime
#  stats         :jsonb            not null
#  status        :string           default("pending"), not null
#  triggered_by  :string           default("manual"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  rag_flow_id   :bigint           not null
#
# Indexes
#
#  index_rag_runs_on_rag_flow_id             (rag_flow_id)
#  index_rag_runs_on_rag_flow_id_and_status  (rag_flow_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (rag_flow_id => rag_flows.id)
#
require "rails_helper"

RSpec.describe RagRun do
  describe "associations" do
    it { is_expected.to belong_to(:rag_flow).inverse_of(:rag_runs) }
    it { is_expected.to have_many(:rag_step_runs).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:triggered_by) }
  end

  describe "enums" do
    subject(:rag_run) { described_class.new }

    it {
      expect(rag_run).to define_enum_for(:status).backed_by_column_of_type(:string).with_values(
        pending: "pending",
        running: "running",
        completed: "completed",
        failed: "failed",
        cancelled: "cancelled",
      )
    }
  end

  describe "#duration" do
    it "returns nil when not started" do
      run = build(:rag_run, started_at: nil)
      expect(run.duration).to be_nil
    end

    it "returns elapsed seconds when running" do
      run = build(:rag_run, started_at: 5.seconds.ago, completed_at: nil)
      expect(run.duration).to be_within(1).of(5)
    end

    it "returns total duration when completed" do
      run = build(:rag_run, started_at: 10.seconds.ago, completed_at: 5.seconds.ago)
      expect(run.duration).to be_within(1).of(5)
    end
  end

  describe "#finished?" do
    let(:pipeline) { create(:rag_flow) }

    it "returns true for completed runs" do
      expect(create(:rag_run, :completed, rag_flow: pipeline)).to be_finished
    end

    it "returns true for failed runs" do
      expect(create(:rag_run, :failed, rag_flow: pipeline)).to be_finished
    end

    it "returns true for cancelled runs" do
      expect(create(:rag_run, :cancelled, rag_flow: pipeline)).to be_finished
    end

    it "returns false for pending runs" do
      expect(create(:rag_run, :pending, rag_flow: pipeline)).not_to be_finished
    end

    it "returns false for running runs" do
      expect(create(:rag_run, :running, rag_flow: pipeline)).not_to be_finished
    end
  end

  describe "stats helpers" do
    let(:run) do
      build(:rag_run,
            stats: { "documents_loaded" => 10, "documents_skipped" => 3,
                     "chunks_created" => 50, "embeddings_generated" => 50, },)
    end

    it "returns documents_loaded from stats" do
      expect(run.documents_loaded).to eq(10)
    end

    it "returns documents_skipped from stats" do
      expect(run.documents_skipped).to eq(3)
    end

    it "returns documents_processed from stats" do
      expect(run.documents_processed).to eq(7)
    end

    it "returns chunks_created from stats" do
      expect(run.chunks_created).to eq(50)
    end

    it "returns embeddings_generated from stats" do
      expect(run.embeddings_generated).to eq(50)
    end

    it "defaults to 0 for empty stats" do
      empty_run = build(:rag_run, stats: {})
      expect(empty_run.documents_loaded).to eq(0)
      expect(empty_run.documents_skipped).to eq(0)
      expect(empty_run.chunks_created).to eq(0)
      expect(empty_run.embeddings_generated).to eq(0)
    end

    it "returns documents_stored from stats" do
      run = build(:rag_run, stats: { "documents_stored" => 8 })
      expect(run.documents_stored).to eq(8)
    end
  end

  describe "#stale?" do
    let(:pipeline) { create(:rag_flow) }

    it "returns false for finished runs" do
      [:completed, :failed, :cancelled].each do |status|
        run = create(:rag_run, status, rag_flow: pipeline,
                                       updated_at: (RagRun::STALE_TIMEOUT + 1.minute).ago,)
        expect(run).not_to be_stale
      end
    end

    it "returns false when updated recently" do
      run = create(:rag_run, :running, rag_flow: pipeline)
      expect(run).not_to be_stale
    end

    it "returns true when running without a heartbeat for longer than STALE_TIMEOUT" do
      run = create(:rag_run, :running, rag_flow: pipeline)
      run.update_column(:updated_at, (RagRun::STALE_TIMEOUT + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations
      expect(run.reload).to be_stale
    end

    it "returns true when pending for longer than STALE_TIMEOUT" do
      run = create(:rag_run, :pending, rag_flow: pipeline)
      run.update_column(:updated_at, (RagRun::STALE_TIMEOUT + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations
      expect(run.reload).to be_stale
    end
  end

  describe "#recover_if_stale!" do
    let(:pipeline) { create(:rag_flow) }

    context "when not stale" do
      it "does nothing" do
        run = create(:rag_run, :running, rag_flow: pipeline)
        expect { run.recover_if_stale! }.not_to(change { run.reload.status })
      end
    end

    context "when stale" do
      let(:run) do
        r = create(:rag_run, :running, rag_flow: pipeline)
        r.update_column(:updated_at, (RagRun::STALE_TIMEOUT + 1.minute).ago) # rubocop:disable Rails/SkipsModelValidations
        r.reload
      end

      it "marks the run as failed" do
        expect { run.recover_if_stale! }.to change { run.reload.status }.to("failed")
      end

      it "sets completed_at" do
        run.recover_if_stale!
        expect(run.reload.completed_at).to be_present
      end

      it "sets a descriptive error_message" do
        run.recover_if_stale!
        expect(run.reload.error_message).to include("Worker process terminated unexpectedly")
      end

      it "skips pending and running step runs" do
        step_run = create(:rag_step_run, rag_run: run, status: :running)
        run.recover_if_stale!
        expect(step_run.reload.status).to eq("skipped")
      end
    end
  end

  describe "#broadcast_progress" do
    let(:run) { create(:rag_run, rag_flow: create(:rag_flow)) }

    before do
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    it "logs and skips oversized postgres broadcast payloads" do
      allow(run).to receive(:broadcast_replace_to)
        .and_raise(PG::InvalidParameterValue, "payload string too long")

      expect { run.broadcast_progress }.not_to raise_error
      expect(Rails.logger).to have_received(:warn)
        .with(/\[RagRun\] Broadcast skipped for run #{run.id} — PG payload too large: payload string too long/)
    end

    it "broadcasts the run detail on success" do
      allow(run).to receive(:broadcast_replace_to)

      expect { run.broadcast_progress }.not_to raise_error
      expect(run).to have_received(:broadcast_replace_to).with(
        "rag_run_#{run.id}",
        target: "rag-run-#{run.id}",
        partial: "admin/rag/runs/run_detail",
        locals: { run: },
      )
      expect(Rails.logger).not_to have_received(:warn)
      expect(Rails.logger).not_to have_received(:error)
    end

    it "logs other broadcast errors without raising" do
      allow(run).to receive(:broadcast_replace_to).and_raise(StandardError, "broadcast failed")

      expect { run.broadcast_progress }.not_to raise_error
      expect(Rails.logger).to have_received(:error)
        .with(/\[RagRun\] Broadcast error for run #{run.id}: StandardError — broadcast failed/)
    end

    it "logs broadcast errors even when the exception has no backtrace" do
      error = StandardError.new("broadcast failed")
      allow(error).to receive(:backtrace).and_return(nil)
      allow(run).to receive(:broadcast_replace_to) { raise error }

      expect { run.broadcast_progress }.not_to raise_error
      expect(Rails.logger).to have_received(:error)
        .with("[RagRun] Broadcast error for run #{run.id}: StandardError — broadcast failed ()")
    end
  end
end
