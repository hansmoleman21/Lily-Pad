# Okta resources managed by Terraform. 

resource "okta_app_oauth" "dashboard" {
  label                      = "Lily Pad Dashboard"
  type                       = "browser"
  grant_types                = ["authorization_code"]
  response_types             = ["code"]
  redirect_uris              = ["https://${aws_cloudfront_distribution.dashboard.domain_name}/index.html"]
  post_logout_redirect_uris  = ["https://${aws_cloudfront_distribution.dashboard.domain_name}/"]
  token_endpoint_auth_method = "none" # public client (SPA): no secret, PKCE instead
  pkce_required              = true

  # Kept because they differ from the provider's defaults: omitting them
  # would make Terraform change the live app.
  consent_method = "REQUIRED" # provider default is TRUSTED
  issuer_mode    = "DYNAMIC"
  login_mode     = "DISABLED"
  hide_ios       = true # no tile on the Okta dashboard; you sign in from the page itself
  hide_web       = true

  # The app's sign-on (authentication) policy, assigned in the console. Without
  # this line, the provider would switch the app to the org's default policy.
  authentication_policy = "rst17ligvfe01uo9E698"
}

# Who may sign in to the dashboard. Membership is managed in Okta (like the AWS
# push groups); Terraform owns the group and the app assignment.
resource "okta_group" "lily_pad_dashboard_users" {
  name        = "lily-pad-dashboard-users"
  description = "Can sign in to the Lily Pad private dashboard"
}

# Owns the app's entire set of group assignments. Any group assigned by hand
# and not listed here would be removed.
resource "okta_app_group_assignments" "lily_pad_dashboard" {
  app_id = okta_app_oauth.dashboard.id
  group {
    id = okta_group.lily_pad_dashboard_users.id
  }
}

resource "okta_group" "lily_pad_admins" {
  name        = "lily-pad-admins"
  description = "Admins for the Lily Pad app"
}