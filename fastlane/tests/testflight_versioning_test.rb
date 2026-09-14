# Exercise the real lanes without fastlane, signing credentials, or network access.
class TestFlightLaneHarness
  attr_accessor :latest, :lookup_error
  attr_reader :queries, :builds, :uploads

  def initialize
    @lanes = {}
    @platform = nil
    instance_eval(File.read(File.expand_path('../Fastfile', __dir__)), 'Fastfile')
  end

  def default_platform(*)
  end

  def desc(*)
  end

  def platform(name)
    previous = @platform
    @platform = name
    yield
  ensure
    @platform = previous
  end

  def lane(name, &block)
    @lanes[[@platform, name]] = block
  end

  def run(platform, lane)
    @queries, @builds, @uploads = [], [], []
    instance_exec(&@lanes.fetch([platform, lane]))
  end

  def latest_testflight_build_number(**options)
    @queries << options
    raise lookup_error if lookup_error
    latest
  end

  def setup_ci
  end

  def build_app(**options)
    @builds << options
  end
  alias build_mac_app build_app

  def upload_to_testflight(**options)
    @uploads << options
  end
end

def check(condition, message)
  raise message unless condition
end

harness = TestFlightLaneHarness.new
# Override only authentication; all version lookup and archive wiring stays real.
harness.define_singleton_method(:asc_api_key) { { key_id: 'offline-fixture' } }
checks = 0
[:ios, :mac].product([:beta, :ci_beta]).each do |platform, lane|
  [[1, 2], [42, 43], ['42.7.9', 43]].each do |latest, expected|
    harness.latest = latest
    harness.run(platform, lane)
    query = harness.queries.fetch(0)
    check(harness.queries.length == 1, 'Expected one build lookup')
    check(query[:platform] == (platform == :ios ? 'ios' : 'osx'), 'Wrong platform')
    check(!query.key?(:version) && query[:live] == false, 'Must query across versions')
    check(query[:initial_build_number] == 1, 'First upload must allocate build 2')
    check(query[:api_key] == (lane == :ci_beta ? { key_id: 'offline-fixture' } : nil), 'Wrong authentication')
    args = harness.builds.fetch(0).fetch(:xcargs).split
    check(args.include?("CURRENT_PROJECT_VERSION=#{expected}"), 'Archive must use the next build number')
    check(args.include?('-allowProvisioningUpdates') == (lane == :ci_beta), 'Signing flags changed')
    check(harness.uploads.length == 1, 'Expected one upload')
    checks += 1
  end

  harness.lookup_error = 'App Store Connect unavailable'
  begin
    harness.run(platform, lane)
    raise 'Expected the lookup failure to stop the lane'
  rescue RuntimeError => error
    check(error.message == harness.lookup_error, 'Lookup failure was swallowed')
    check(harness.builds.empty? && harness.uploads.empty?, 'Must not build or upload after a failed lookup')
    checks += 1
  ensure
    harness.lookup_error = nil
  end
end
puts "#{checks} TestFlight versioning scenarios passed"
