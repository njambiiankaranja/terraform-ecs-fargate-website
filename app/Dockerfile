# Start from the official small Nginx image, pinned to a version
FROM nginx:1.27-alpine

# Copy the website into the folder Nginx serves
COPY index.html /usr/share/nginx/html/index.html

# Nginx listens on port 80 inside the container
EXPOSE 80