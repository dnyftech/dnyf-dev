"use strict";

const fs = require("fs");
const path = require("path");

function resolveRoot() {
  return process.env.DNYF_ROOT || path.join(
    process.env.HOME || process.cwd(),
    "DNYF-DEV"
  );
}

const ROOT = resolveRoot();

const REGISTRY_FILE = path.join(
  ROOT,
  "registry",
  "dnyf-unified-device-registry.json"
);

function readRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY_FILE, "utf8"));
}

function getDevice(deviceId) {
  const registry = readRegistry();
  return registry.devices[String(deviceId).toLowerCase()] || null;
}

function listDevices() {
  const registry = readRegistry();
  return Object.values(registry.devices || {});
}

function isSelfTrusted() {
  const registry = readRegistry();
  return registry.policy?.self_trust === true;
}

function isSelfPaired() {
  const registry = readRegistry();
  return registry.policy?.self_pairing === true;
}

function isAutomaticallyTrusted() {
  const registry = readRegistry();
  return registry.policy?.automatic_trust === true;
}

module.exports = {
  ROOT,
  REGISTRY_FILE,
  readRegistry,
  getDevice,
  listDevices,
  isSelfTrusted,
  isSelfPaired,
  isAutomaticallyTrusted
};
