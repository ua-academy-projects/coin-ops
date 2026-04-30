resource "google_compute_instance" "vm" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags


  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size
    }
  }

  network_interface {
    network    = var.vpc_name
    subnetwork = var.subnet_name

    dynamic "access_config" {
      for_each = var.has_external_ip ? [1] : []
      content {}
    }
  }
}