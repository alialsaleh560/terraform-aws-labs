name        = "prod"
cidr        = "10.20.0.0/16"# new cidr range (+10 from dev)
environment = "prod"
az_count    = 3 #here in prod we need 3 az , while in dev we have 2