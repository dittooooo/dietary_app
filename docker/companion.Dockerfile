FROM node:22-bookworm-slim
WORKDIR /app
COPY companion/companion_js/package*.json ./
RUN npm ci --omit=dev
COPY companion/companion_js/*.js ./
COPY companion/companion_js/prompts ./prompts
CMD ["node", "companion-agent.js"]
