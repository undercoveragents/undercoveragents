# frozen_string_literal: true

module Missions
  module RunnerFrameCompatibility
    private

    def runner_frame_from_args(args)
      return args.first if args.one? && args.first.is_a?(RunnerFrame)

      run, graph, context, scheduler = args
      RunnerFrame.new(run:, graph:, context:, scheduler:)
    end

    def iterator_flow_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, node_id, node_data, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_id, node_data]
    end

    def parallel_iterator_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, node_id, collection, start_index, results, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_id, collection, start_index, results]
    end

    def loop_finish_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, node_id, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_id]
    end

    def branch_edge_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, edge, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), edge]
    end

    def branch_node_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, node_id, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_id]
    end

    def follow_edge_args(args, options)
      return [args[0], args[1], args[2], options] if args.first.is_a?(RunnerFrame)

      run, graph, context, node_id, port = args
      scheduler = options.delete(:scheduler)
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_id, port, options]
    end

    def skip_node_args(args)
      return args if args.first.is_a?(RunnerFrame)

      run, graph, context, node_details, incoming_edge, scheduler = args
      [RunnerFrame.new(run:, graph:, context:, scheduler:), node_details, incoming_edge]
    end
  end
end
