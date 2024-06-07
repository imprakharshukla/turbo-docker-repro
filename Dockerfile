ARG NODE_VERSION=18.17.0

# Alpine image
FROM node:${NODE_VERSION}-alpine AS alpine
RUN apk update
RUN apk add --no-cache libc6-compat
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

# Setup npm on the alpine base
FROM alpine as base
RUN npm install turbo --global


# Prune projects
FROM base AS pruner
ARG PROJECT

WORKDIR /app
COPY . .
RUN turbo prune ${PROJECT} --docker

# Build the project
FROM base AS builder
ARG PROJECT

WORKDIR /app

# Copy lockfile and package.json's of isolated subworkspace
COPY --from=pruner /app/out/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=pruner /app/out/json/ .

# Install app dependencies with caching
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --filter ${PROJECT}

# Copy source code of isolated subworkspace
COPY --from=pruner /app/out/full/ .

# Generate Prisma Client
RUN turbo run db:generate

# Build the project
RUN turbo run build ${PROJECT}

# Install app dependencies with caching
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile --filter ${PROJECT}
RUN rm -rf ./**/*/src

# Final image
FROM alpine AS runner
ARG PROJECT

WORKDIR /app
COPY --from=builder /app .
WORKDIR /app/apps/${PROJECT}

ARG PORT=3002
ENV PORT=${PORT}
ENV NODE_ENV=production


# Install Doppler CLI
RUN wget -q -t3 'https://packages.doppler.com/public/cli/rsa.8004D9FF50437357.key' -O /etc/apk/keys/cli@doppler-8004D9FF50437357.rsa.pub && \
    echo 'https://packages.doppler.com/public/cli/alpine/any-version/main' | tee -a /etc/apk/repositories && \
    apk add doppler

EXPOSE ${PORT}

# Command to run the application
CMD doppler run -c prd_backend -- pnpm run start --filter backend