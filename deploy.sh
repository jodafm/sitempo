#!/bin/bash
# Build Flutter web and deploy to Vercel with API proxy
set -e

echo "Building Flutter web..."
flutter build web

echo "Preparing deploy directory..."
rm -rf .vercel_deploy
mkdir .vercel_deploy
cp -r build/web/* .vercel_deploy/
cp -r api .vercel_deploy/api
cp vercel.json .vercel_deploy/

echo "Deploying to Vercel..."
cd .vercel_deploy
npx vercel deploy --prod

echo "Cleaning up..."
cd ..
rm -rf .vercel_deploy

echo "Done!"
