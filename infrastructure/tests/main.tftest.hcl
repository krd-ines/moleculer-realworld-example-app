mock_provider "aws" {
  override_during = plan

  mock_resource "aws_subnet" {
    defaults = {
      id = "subnet-12345"
    }
  }

  mock_resource "aws_instance" {
    defaults = {
      private_ip = "10.0.1.50"
      id         = "i-0123456789mock"
    }
  }

  # --- NEW: Mock for Network ACLs ---
  mock_resource "aws_network_acl" {
    defaults = {
      id = "nacl-99999"
    }
  }
}

run "verify_vpc_and_subnets_security" {
  command = plan

  # --- EXISTING INFRA TESTS ---
  assert {
    condition     = length(aws_instance.workers) == 6
    error_message = "Infrastructure must have exactly 6 worker nodes."
  }

  # --- NEW NACL ATTACHMENT TESTS ---
  
  assert {
    condition     = contains(aws_network_acl.public_nacl.subnet_ids, aws_subnet.public.id)
    error_message = "The Public NACL is not attached to the Public Subnet."
  }

  assert {
    condition     = contains(aws_network_acl.app_nacl.subnet_ids, aws_subnet.private_app.id)
    error_message = "The App NACL is not attached to the Private App Subnet."
  }

  assert {
    condition     = contains(aws_network_acl.db_nacl.subnet_ids, aws_subnet.private_db.id)
    error_message = "The DB NACL is not attached to the Private DB Subnet."
  }
}

run "verify_nacl_logic" {
  command = plan

  # Check: Ensure the DB NACL has a specific rule to allow MongoDB (27017)
  # This verifies that the rule exists in your terraform code logic.
  assert {
    condition     = anytrue([
      for rule in aws_network_acl.db_nacl.ingress : rule.from_port == 27017
    ])
    error_message = "The DB NACL is missing a rule to allow MongoDB traffic on port 27017."
  }
}

run "verify_outputs_logic" {
  command = plan

  assert {
    condition     = can(regex("^mongodb://", output.mongodb_connection_uri))
    error_message = "The MongoDB output URI is malformed."
  }
}