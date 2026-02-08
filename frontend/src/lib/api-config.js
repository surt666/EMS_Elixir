// API Configuration
// Provides base URLs for API calls

export const apiConfig = {
	// CloudFront distribution URL
	cloudfrontUrl: import.meta.env.PUBLIC_CLOUDFRONT_URL ?? '',

	// Base URL for API calls (proxied to localhost:4000 in dev)
	baseUrl: import.meta.env.PUBLIC_API_BASE_URL ?? '',

	// API endpoints
	endpoints: {
		hierarchy: '/hierarchy',
	}
};

/**
 * Helper function to build full API URL
 * @param {string} path - The API path (e.g., '/hierarchy/query/partners')
 * @returns {string} Full API URL
 */
export function buildApiUrl(path) {
	// Remove leading slash from path if present
	const cleanPath = path.startsWith('/') ? path.slice(1) : path;
	return `${apiConfig.baseUrl}/${cleanPath}`;
}
