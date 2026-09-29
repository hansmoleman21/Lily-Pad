# Okta resources managed by Terraform. The dashboard app was built by hand in
# Part 1 and is imported here; delete this import block after the apply.

import {
  to = okta_app_oauth.lily_pad_dashboard
  id = "0oa17mfxictemtIDi698" # for OIDC apps, app ID = client ID
}

resource "okta_app_oauth" "lily_pad_dashboard" {
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
