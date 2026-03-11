export interface GeminiResponse {
  text: string;
  success: boolean;
  error?: string;
}

export interface Conversation {
  id: string;
  messages: ConversationMessage[];
  metadata: ConversationMetadata;
}

export interface ConversationMessage {
  role: 'user' | 'assistant' | 'developer';
  content: string;
  timestamp: Date;
}

export interface ConversationMetadata {
  created: Date;
  lastActive: Date;
  topic?: string;
  contextLimit?: number;
}
