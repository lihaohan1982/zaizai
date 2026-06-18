"use strict";
/**
 * Location encryption/decryption utilities.
 *
 * Current implementation: **passthrough** (no-op).
 * TODO (P0): Replace with AES-GCM encryption using device keychain keys.
 * When real encryption is implemented, encryptLocation/decryptLocation must be
 * symmetric — the client encrypts before uploading, the server decrypts before
 * returning to authorized friends.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.encryptLocation = encryptLocation;
exports.decryptLocation = decryptLocation;
/**
 * Encrypt location coordinates (client-side use).
 * Currently a passthrough — returns raw values.
 */
function encryptLocation(lat, lng) {
    // TODO: AES-GCM encrypt with device-derived key
    return { lat: lat.toString(), lng: lng.toString() };
}
/**
 * Decrypt location coordinates (server-side use).
 * Currently a passthrough — returns parsed floats.
 */
function decryptLocation(encryptedLat, encryptedLng) {
    // TODO: AES-GCM decrypt with device-derived key
    return {
        lat: parseFloat(encryptedLat),
        lng: parseFloat(encryptedLng),
    };
}
