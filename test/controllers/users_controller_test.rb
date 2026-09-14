require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Was generated as `users_dashboard_url`, which has never been a route here
  # (it is `dashboard_path`), and it never signed in -- so the app's only
  # non-commented test had been failing since it was written.
  test "dashboard requires authentication" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "shows the dashboard to a signed-in user" do
    sign_in users(:learner)

    get dashboard_path

    assert_response :success
  end
end
