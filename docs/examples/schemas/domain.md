Resource State Pattern Example (Domain)

sample schema pattern:

```go
resp.Schema = schema.Schema{
  Attributes: map[string]schema.Attribute{
    "id": schema.StringAttribute{Computed: true},
    "domain": schema.StringAttribute{Required: true},
    "description": schema.StringAttribute{Optional: true, Computed: true},
    "from_name": schema.StringAttribute{Optional: true, Computed: true},
    "active": schema.BoolAttribute{Optional: true, Computed: true},
    "catch_all": schema.BoolAttribute{Optional: true, Computed: true},
    "aliases_count": schema.Int64Attribute{Computed: true},
    "default_recipient": schema.StringAttribute{Optional: true, Computed: true},
    "auto_create_regex": schema.StringAttribute{Optional: true, Computed: true},
    "created_at": schema.StringAttribute{Computed: true},
    "updated_at": schema.StringAttribute{Computed: true},
    "domain_verified_at": schema.StringAttribute{Computed: true},
    "domain_mx_validated_at": schema.StringAttribute{Computed: true},
    "domain_sending_verified_at": schema.StringAttribute{Computed: true},
  },
}
```
