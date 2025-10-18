
# Geçici Ubuntu sunucu ile Talos snapshot oluştur
resource "hcloud_server" "talos_snapshot_builder" {
  name        = "talos-snapshot-builder"
  server_type = "cx22"
  image       = "ubuntu-22.04"
  location    = var.location

  user_data = <<-EOT
    #!/bin/bash
    set -e
    
    # Talos Image Factory'den Hetzner-optimized image indir
    curl -LO https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.11.3/hcloud-amd64.raw.xz
    xz -d hcloud-amd64.raw.xz
    
    # Disk'e yaz
    dd if=hcloud-amd64.raw of=/dev/sda bs=4M status=progress
    sync
    
    # Snapshot hazır sinyali
    echo "SNAPSHOT_READY" > /tmp/snapshot_ready
  EOT

  labels = {
    purpose = "talos-snapshot-builder"
  }
}

# Sunucunun hazır olmasını bekle
resource "null_resource" "wait_for_snapshot_ready" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Talos installation to complete..."
      sleep 180
    EOT
  }

  depends_on = [hcloud_server.talos_snapshot_builder]
}

# Snapshot oluştur
resource "hcloud_snapshot" "talos" {
  server_id   = hcloud_server.talos_snapshot_builder.id
  description = "Talos OS v1.11.3 (Image Factory) for Hetzner Cloud"
  labels = {
    os          = "talos"
    version     = "1.11.3"
    source      = "image-factory"
    schematic   = "376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba"
  }

  depends_on = [null_resource.wait_for_snapshot_ready]
}

# Snapshot builder sunucuyu sil
resource "null_resource" "cleanup_builder" {
  provisioner "local-exec" {
    command = <<-EOT
      # Builder sunucu artık gerekli değil, snapshot aldık
      echo "Snapshot created: ${hcloud_snapshot.talos.id}"
    EOT
  }

  depends_on = [hcloud_snapshot.talos]
}
