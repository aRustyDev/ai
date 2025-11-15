resource "addy_domain" "managed" {
  domain = "example.com"

  # Uncomment optional attributes once supported by provider schema:
  # description       = "Managed domain"
  # from_name         = "Example Sender"
  # active            = true
  # catch_all         = true
  # auto_create_regex = "^prefix"
}

# (Later) Data source usage after addy_domain data source exists:
# data "addy_domain" "managed_lookup" {
#   id = addy_domain.managed.id
# }

output "managed_domain_id" {
  value = addy_domain.managed.id
}
