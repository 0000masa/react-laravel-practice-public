FROM nginx:alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY ./environment/ecr/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]