// API Configuration
// Provides base URLs for API calls

export const apiConfig = {
	// CloudFront distribution URL
	cloudfrontUrl: import.meta.env.PUBLIC_CLOUDFRONT_URL || 'https://d368wcanc53tdl.cloudfront.net',

	// Base URL for API calls (same as CloudFront for now)
	baseUrl: import.meta.env.PUBLIC_API_BASE_URL || 'https://d368wcanc53tdl.cloudfront.net',

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
