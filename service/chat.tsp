import "@typespec/http";
import "../main.tsp";

using Http;
using SciEdu;

namespace SciEdu.Chat;

// -----------------------------------------------------------------------------
// Models
// -----------------------------------------------------------------------------

@doc("The role of the message author.")
enum MessageRole {
  User: "user",
  Assistant: "assistant",
}

@doc("The processing status of a message.")
enum MessageStatus {
  Streaming: "streaming",
  Done: "done",
  Error: "error",
}

@doc("A single message in a chat session.")
model Message {
  @doc("Message ID")
  id: uuid;

  @doc("Message content")
  content: string;

  @doc("Role of the message author")
  role: MessageRole;

  @doc("ID of the previous message in the chain")
  previousID?: uuid;

  @doc("Processing status of the message")
  status: MessageStatus;

  @doc("Timestamp when the message was created")
  createdAt: utcDateTime;
}

@doc("A content delta chunk from the SSE stream.")
model StreamDelta {
  @doc("The streamed content fragment")
  content: string;
}

// -----------------------------------------------------------------------------
// Operations
// -----------------------------------------------------------------------------

@tag("Chat")
@route("/chat")
namespace Chats {
  @doc("Create a new chat session.")
  @post
  op create(): {
    @statusCode statusCode: 201;
    @body body: {
      chatID: uuid;
    };
  } | {
    @statusCode statusCode: 401;
    @body error: SciEdu.Unauthorized;
  };

  @route("/{chatId}/messages")
  namespace Messages {
    @doc("List all messages in a chat session.")
    @get
    op list(@path chatId: uuid): {
      @statusCode statusCode: 200;
      @body body: {
        messages: Message[];
      };
    } | {
      @statusCode statusCode: 401;
      @body error: SciEdu.Unauthorized;
    } | {
      @statusCode statusCode: 404;
      @body error: SciEdu.ProblemDetail;
    };

    @doc("Send a message to a chat session. Returns the sent message and the ID of the pending reply message.")
    @post
    op create(
      @path chatId: uuid,
      @body body: {
        content: string;
        previousID?: uuid;
      },
    ):
      | {
          @statusCode statusCode: 201;
          @body body: {
            @doc("The user's message that was just sent. Its `id` is the ID of the user's message.")
            message: Message;

            @doc("""
              The ID of the assistant's reply message, which is pre-created in a `streaming` state.
              The SSE stream endpoint (`GET /chat/stream/{messageId}`) expects the assistant's message ID — that is this field.
              The `message.id` in this response is the user's message ID, which cannot be used to open a stream.
              """)
            replyMessageID: uuid;
          };
        }
      | {
          @statusCode statusCode: 400;
          @body error: SciEdu.ProblemDetail;
        }
      | {
          @statusCode statusCode: 401;
          @body error: SciEdu.Unauthorized;
        }
      | {
          @statusCode statusCode: 404;
          @body error: SciEdu.ProblemDetail;
        };
  }

  @route("/stream/{messageId}")
  namespace Stream {
    @doc("Stream the assistant reply for a given message using Server-Sent Events. Returns 404 if the messageId does not exist, 400 if the message has no reply pending yet.")
    @get
    op get(@path messageId: uuid):
      | {
          @statusCode statusCode: 200;
          @header("Content-Type") contentType: "text/event-stream";
          @header("Cache-Control") cacheControl: "no-cache";
          @header("Connection") connection: "keep-alive";
          @body body: StreamDelta;
        }
      | {
          @statusCode statusCode: 400;
          @body error: SciEdu.ProblemDetail;
        }
      | {
          @statusCode statusCode: 401;
          @body error: SciEdu.Unauthorized;
        }
      | {
          @statusCode statusCode: 404;
          @body error: SciEdu.ProblemDetail;
        };
  }
}
