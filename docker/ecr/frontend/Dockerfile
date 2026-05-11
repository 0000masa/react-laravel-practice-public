FROM node:20-alpine AS build
WORKDIR /app

COPY frontend/www/package*.json ./
RUN npm ci
COPY frontend/www/ .
RUN npm run build

FROM nginx:alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY ./environment/ecr/react-nginx.conf /etc/nginx/conf.d/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
