/**
 * Token estimation and response chunking utilities
 */

export interface TokenEstimate {
  characters: number;
  estimatedTokens: number;
  isOverLimit: boolean;
}

export interface ResponseChunk {
  content: string;
  chunkIndex: number;
  totalChunks: number;
  tokenEstimate: TokenEstimate;
  hasMore: boolean;
}

export function estimateTokens(text: string): TokenEstimate {
  const characters = text.length;
  const estimatedTokens = Math.ceil(characters / 3.5);
  const isOverLimit = estimatedTokens > 20000;
  
  return {
    characters,
    estimatedTokens,
    isOverLimit
  };
}

export function chunkResponse(
  text: string, 
  maxTokensPerChunk: number = 18000,
  requestedPage: number = 1
): ResponseChunk {
  const estimate = estimateTokens(text);
  
  if (!estimate.isOverLimit && estimate.estimatedTokens <= maxTokensPerChunk) {
    return {
      content: text,
      chunkIndex: 1,
      totalChunks: 1,
      tokenEstimate: estimate,
      hasMore: false
    };
  }
  
  const maxCharsPerChunk = Math.floor(maxTokensPerChunk * 3.5);
  const totalChunks = Math.ceil(text.length / maxCharsPerChunk);
  const pageNum = Math.max(1, Math.min(requestedPage, totalChunks));
  
  const startIndex = (pageNum - 1) * maxCharsPerChunk;
  const endIndex = Math.min(startIndex + maxCharsPerChunk, text.length);
  const chunkContent = text.slice(startIndex, endIndex);
  
  return {
    content: chunkContent,
    chunkIndex: pageNum,
    totalChunks,
    tokenEstimate: estimateTokens(chunkContent),
    hasMore: pageNum < totalChunks
  };
}

export function formatPaginatedResponse(
  chunk: ResponseChunk,
  _totalText: string,
  requestId?: string
): string {
  let response = chunk.content;
  
  if (chunk.totalChunks > 1) {
    response += `\n\n--- Page ${chunk.chunkIndex} of ${chunk.totalChunks} ---`;
    response += `\n📊 Tokens: ~${chunk.tokenEstimate.estimatedTokens}`;
    if (chunk.hasMore) response += `\n⏭️ Use page=${chunk.chunkIndex + 1} for next chunk`;
    if (requestId) response += `\n🔍 Request ID: ${requestId}`;
  }
  
  return response;
}
