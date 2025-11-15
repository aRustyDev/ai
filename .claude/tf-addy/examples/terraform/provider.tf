terraform {
  required_version = ">= 1.6.0"
  required_providers {
    addy = {
      source  = "arustydev/addy"
      version = "~> 0.1.0"
    }
  }
}

# Preferred: rely on ADDY_API_KEY env var.
# export ADDY_API_KEY="xxxxxxxx"
# Or set TF_VAR_addy_api_key to feed variable automatically.
provider "addy" {
  # Omit api_key attribute entirely to use env ADDY_API_KEY.
  # Uncomment if you need explicit override:
  # api_key = var.addy_api_key
}

variable "addy_api_key" {
  type      = string
  sensitive = true
  nullable  = false
  description = "Addy API key (optional if ADDY_API_KEY env var is set)."
}
