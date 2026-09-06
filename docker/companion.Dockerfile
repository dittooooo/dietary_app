FROM node:22-bookworm-slim
WORKDIR /app
COPY companion/package*.json ./
RUN npm ci --omit=dev
COPY companion/*.js ./
COPY companion/prompts ./prompts
CMD ["node", "companion-agent.js"]
