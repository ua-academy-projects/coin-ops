output "service_accounts" {
  value = {
    for key, account in google_service_account.this : key => {
      email = account.email
    }
  }
}
