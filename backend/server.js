require("dotenv").config();

const http = require("http");
const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const morgan = require("morgan");
const path = require("path");
const { Server } = require("socket.io");

const uploadRoutes = require("./src/routes/upload");
const notificationRoutes = require("./src/routes/notifications");
const paymentRoutes = require("./src/routes/payments");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*", methods: ["GET", "POST"] },
});
const PORT = process.env.PORT || 5001;

app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(cors({ origin: "*" }));
app.use(morgan("dev"));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(
  "/productImages",
  express.static(path.join(__dirname, "productImages"))
);
app.use("/uploads", express.static(path.join(__dirname, "src/uploads")));

app.use("/api/upload", uploadRoutes);
app.use("/api/notifications", notificationRoutes);
app.use("/api/payments", paymentRoutes);
app.use(
  "/paymentScreenshots",
  express.static(path.join(__dirname, "paymentScreenshots"))
);

app.get("/api/health", (_req, res) => {
  res.json({
    status: "OK",
    message: "Three Seasons Upload Server is running.",
    timestamp: new Date().toISOString(),
  });
});

app.use((_req, res) =>
  res.status(404).json({ success: false, message: "Route not found." })
);

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error("Unhandled error:", err);
  res.status(500).json({ success: false, message: "Internal server error." });
});

// ─── Socket.IO ────────────────────────────────────────────────────────────────

io.on("connection", (socket) => {
  // Join a conversation room so events are scoped to that chat
  socket.on("join_conversation", (conversationId) => {
    socket.join(conversationId);
  });

  // Leave a conversation room
  socket.on("leave_conversation", (conversationId) => {
    socket.leave(conversationId);
  });

  // Broadcast a new message to everyone else in the conversation room
  socket.on("send_message", ({ conversationId, message }) => {
    socket.to(conversationId).emit("new_message", message);
  });

  // Broadcast typing to everyone else in the room
  socket.on("typing", ({ conversationId, userId }) => {
    socket.to(conversationId).emit("typing", { userId });
  });

  // Broadcast stop-typing to everyone else in the room
  socket.on("stop_typing", ({ conversationId, userId }) => {
    socket.to(conversationId).emit("stop_typing", { userId });
  });
});

// ─────────────────────────────────────────────────────────────────────────────

server.listen(PORT, () => {
  console.log(
    `Three Seasons Server running on port ${PORT} [${
      process.env.NODE_ENV || "development"
    }]`
  );
});

server.on("error", (err) => {
  if (err.code === "EADDRINUSE") {
    console.error(
      `Port ${PORT} is already in use. Run: lsof -ti :${PORT} | xargs kill -9`
    );
    process.exit(1);
  } else {
    throw err;
  }
});

module.exports = { app, server, io };
