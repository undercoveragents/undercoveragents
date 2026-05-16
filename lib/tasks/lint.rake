# frozen_string_literal: true

namespace :lint do
  desc "Run Brakeman security scanner"
  task brakeman: :environment do
    puts "Running Brakeman..."
    system(
      "bundle exec brakeman --quiet --no-pager --exit-on-warn --exit-on-error --ignore-config config/brakeman.ignore",
    ) || abort("Brakeman failed!")
  end

  desc "Run bundler-audit"
  task bundler_audit: :environment do
    puts "Running bundler-audit..."
    system("bundle exec bundler-audit check --update") || abort("bundler-audit failed!")
  end

  desc "Run importmap audit"
  task importmap_audit: :environment do
    puts "Running importmap audit..."
    # importmap-rails 2.x has a bug where sub-path packages (e.g. @scope/pkg/src)
    # are incorrectly reported as "no version specified" because extract_base_package_name
    # normalises them to @scope/pkg but vendored_packages_without_version checks the
    # full sub-path name. Filter the false-positive warning while preserving real output.
    output = `bin/importmap audit 2>&1`
    exit_code = $CHILD_STATUS.exitstatus
    output.each_line do |line|
      print line unless line.match?(/Ignoring .+ since no version is specified in the importmap/)
    end
    abort("importmap audit failed!") unless exit_code&.zero?
  end

  desc "Run haml-lint"
  task haml_lint: :environment do
    puts "Running haml-lint..."
    system("bundle exec haml-lint") || abort("haml-lint failed!")
  end

  desc "Run all linters"
  task all: ["rubocop", "lint:haml_lint", "lint:brakeman", "lint:bundler_audit", "lint:importmap_audit"]
end

desc "Run all linters"
task lint: "lint:all"
