resource "random_password" "root_password" {
  length  = 32
  special = false
}
