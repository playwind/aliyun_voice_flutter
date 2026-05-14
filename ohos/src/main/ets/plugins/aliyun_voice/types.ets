/**
 * Common type definitions for Aliyun Voice Plugin
 * Provides interfaces for error results and event data
 */

// Error result interface
export interface ErrorResult {
  error: string;
  message: string;
}

// Event data interfaces
export interface TaskIdData {
  taskId: string;
}

export interface TextData {
  text: string;
}

export interface ErrorCodeData {
  code: number;
  message: string;
}

export interface ErrorWithTaskIdData {
  code: number;
  message: string;
  taskId: string;
}

export interface ValueData {
  value: number;
}

// Helper function to create error result
export function createError(error: string, message: string): ErrorResult {
  return { error, message };
}

// Helper function to merge event data
export function mergeEventData(type: string, data: Record<string, Object>): Record<string, Object> {
  const event: Record<string, Object> = {};
  event['type'] = type;
  
  // Manually copy properties from data
  const keys = Object.keys(data);
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    event[key] = data[key];
  }
  
  return event;
}
