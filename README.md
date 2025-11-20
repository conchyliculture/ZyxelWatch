# ZyxelWatch
Simple service to run somewhere, that will pull data from your Zyxel XGS1210-12 admin webpage, and expose a '/metrics' endpoint for Prometheus to scrape.

Example `docker-compose.yml`:

```
services:
  zyxel_exporter:
    build: https://github.com/conchyliculture/ZyxelWatch.git
    container_name: zyxel_exporter
    restart: unless-stopped
    environment:
      RACK_ENV: production
      ZYXEL_HOST: https://192.168.3.20
      ZYXEL_PASSWORD: password
    expose:
      - 4567
```
