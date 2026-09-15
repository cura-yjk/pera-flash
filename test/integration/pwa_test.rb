require "test_helper"

# The app is meant to live on a phone's home screen. Installability is decided
# by the browser from the manifest and the service worker, so a typo here is
# invisible -- the install option simply never appears.
class PwaTest < ActionDispatch::IntegrationTest
  test "the manifest is served and public" do
    get pwa_manifest_path(format: :json)

    assert_response :success
  end

  test "the manifest names icons that exist" do
    get pwa_manifest_path(format: :json)
    manifest = JSON.parse(response.body)

    assert_operator manifest["icons"].size, :>=, 2

    manifest["icons"].each do |icon|
      assert Rails.public_path.join(icon["src"].delete_prefix("/")).exist?,
             "#{icon['src']} is in the manifest but not in public/"
    end
  end

  # Chrome requires both 192 and 512, and a maskable icon keeps the launcher
  # from cropping into the artwork.
  test "the manifest covers the sizes an install prompt needs" do
    manifest = JSON.parse(get_manifest)

    assert_includes manifest["icons"].map { |i| i["sizes"] }, "192x192"
    assert_includes manifest["icons"].map { |i| i["sizes"] }, "512x512"
    assert_includes manifest["icons"].map { |i| i["purpose"] }, "maskable"
  end

  test "the app opens where a returning learner wants to be" do
    manifest = JSON.parse(get_manifest)

    assert_equal "/dashboard", manifest["start_url"]
    assert_equal "standalone", manifest["display"]
  end

  # A navigation with no connection falls back to this page, so it has to be
  # in public/ rather than rendered by the app it cannot reach.
  test "the offline page is a real file" do
    assert Rails.public_path.join("offline.html").exist?
  end

  test "the service worker is served as javascript" do
    get pwa_service_worker_path(format: :js)

    assert_response :success
    assert_match(/addEventListener\("fetch"/, response.body)
  end

  private

  def get_manifest
    get pwa_manifest_path(format: :json)
    response.body
  end
end
