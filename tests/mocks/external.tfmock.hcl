# The secrets directory and the password file as an apply leaves them, for app_uid:app_gid 999:999.
mock_data "external" {
  defaults = {
    result = {
      directory = "700 999:999"
      file      = "600 999:999"
    }
  }
}
