🚀 Odoo 18 Community - Despliegue Automático en Google Cloud Platform
Este repositorio contiene la configuración necesaria para desplegar automáticamente Odoo 18 Community en Google Cloud Platform usando GitHub Actions.
✨ Características

✅ Instalación completamente automatizada de Odoo 18 Community
✅ PostgreSQL configurado automáticamente
✅ Todas las dependencias de Python instaladas
✅ Nombre único automático para cada instancia
✅ Nginx configurado como proxy reverso
✅ Firewall configurado para seguridad básica
✅ SSL/HTTPS ready (configuración futura)
✅ Logs detallados y monitoreo
✅ Scripts de gestión incluidos

🎯 Despliegue Rápido
Haz clic en el botón para desplegar automáticamente:
Mostrar imagen
El botón te llevará a GitHub Actions donde podrás ejecutar el workflow de despliegue.
📋 Prerrequisitos
1. Configuración de Google Cloud Platform

Crear un proyecto en GCP (si no tienes uno)
Habilitar las APIs necesarias:
bashgcloud services enable compute.googleapis.com

Crear una cuenta de servicio:
bashgcloud iam service-accounts create odoo-deployer \
  --display-name="Odoo Deployer"

Asignar permisos necesarios:
bashgcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:odoo-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:odoo-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.securityAdmin"

Generar clave JSON:
bashgcloud iam service-accounts keys create key.json \
  --iam-account=odoo-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com


2. Configuración de GitHub Secrets
En tu repositorio de GitHub, ve a Settings → Secrets and variables → Actions y agrega:
Secret NameDescripciónValorGCP_PROJECT_IDID de tu proyecto de GCPtu-proyecto-idGCP_SA_KEYClave JSON de la cuenta de servicioContenido completo del archivo key.json
🚀 Uso
Opción 1: Usando GitHub Actions (Recomendado)

Ve a la pestaña "Actions" en tu repositorio
Selecciona "Deploy Odoo 18 to Google Cloud Platform"
Haz clic en "Run workflow"
Configura los parámetros (opcional):

Tipo de instancia: e2-medium (recomendado)
Zona: us-central1-a (por defecto)


Haz clic en "Run workflow"

Opción 2: Usando gcloud CLI
bash# Clonar el repositorio
git clone https://github.com/tu-usuario/tu-repo.git
cd tu-repo

# Configurar gcloud
gcloud config set project YOUR_PROJECT_ID

# Crear instancia
INSTANCE_NAME="odoo18-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
gcloud compute instances create $INSTANCE_NAME \
  --zone=us-central1-a \
  --machine-type=e2-medium \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=odoo-server \
  --metadata-from-file startup-script=startup-script.sh
📊 Después del Despliegue
Información que obtendrás:

🌐 URL de acceso: http://IP-EXTERNA:8069
👤 Credenciales iniciales:

Base de datos: odoo
Usuario: admin
Contraseña: admin


📍 Detalles de la instancia: Nombre, IP, zona, etc.

Acceso SSH:
bashgcloud compute ssh NOMBRE-INSTANCIA --zone=ZONA
Comandos útiles en la instancia:
bash# Ver información del sistema
odoo-info

# Ver logs de Odoo
sudo tail -f /var/log/odoo/odoo.log

# Reiniciar Odoo
sudo systemctl restart odoo

# Estado de los servicios
sudo systemctl status odoo
sudo systemctl status postgresql
sudo systemctl status nginx
🏗️ Estructura del Proyecto
.
├── .github/
│   └── workflows/
│       └── deploy-odoo-gcp.yml    # Workflow principal de GitHub Actions
├── startup-script.sh              # Script de instalación automática
├── README.md                      # Esta documentación
└── docs/                         #
