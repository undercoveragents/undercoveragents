FROM node:22-alpine AS build

WORKDIR /site

COPY website/package.json ./
RUN npm install

RUN apk add --no-cache git

COPY website ./website

RUN npx vitepress build website

FROM node:22-alpine AS runtime

WORKDIR /website

ENV NODE_ENV=production

COPY --from=build /site/website/.vitepress/dist ./.vitepress/dist
COPY --from=build /site/website/server.mjs ./server.mjs

EXPOSE 8080

CMD ["node", "server.mjs"]
