#!/usr/bin/env node
/**
 * Auto-create default LibreChat user
 * Runs on container startup to ensure a default user exists
 */

// Change to /app directory to access node_modules
process.chdir('/app');

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const MONGO_URI = process.env.MONGO_URI || 'mongodb://librechat-mongo:27017/LibreChat';
const DEFAULT_USER_EMAIL = process.env.DEFAULT_USER_EMAIL || 'admin@clearndr.local';
const DEFAULT_USER_PASSWORD = process.env.DEFAULT_USER_PASSWORD || 'admin';
const DEFAULT_USER_NAME = process.env.DEFAULT_USER_NAME || 'Admin';

// User Schema (simplified from LibreChat's model)
const userSchema = new mongoose.Schema({
  provider: { type: String, required: true, default: 'local' },
  email: { type: String, required: true, lowercase: true, unique: true },
  emailVerified: { type: Boolean, required: true, default: false },
  password: { type: String, select: false },
  username: { type: String },
  name: { type: String },
  avatar: { type: String },
  role: { type: String, default: 'USER' },
  refreshToken: [{ type: String }],
  plugins: { type: [String], default: undefined },
  createdAt: { type: Date, default: Date.now },
}, { timestamps: true });

const User = mongoose.model('User', userSchema);

async function createDefaultUser() {
  console.log('======================================');
  console.log('LibreChat User Initialization');
  console.log('======================================');

  try {
    // Connect to MongoDB
    console.log('Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI, {
      bufferCommands: false,
      serverSelectionTimeoutMS: 10000,
    });
    console.log('Connected to MongoDB!');

    // Check if user already exists
    console.log(`Checking if user ${DEFAULT_USER_EMAIL} exists...`);
    const existingUser = await User.findOne({ email: DEFAULT_USER_EMAIL });

    if (existingUser) {
      console.log(`User ${DEFAULT_USER_EMAIL} already exists. Skipping creation.`);
      console.log('======================================');
      await mongoose.connection.close();
      process.exit(0);
    }

    // Hash the password
    console.log('Creating new user...');
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(DEFAULT_USER_PASSWORD, salt);

    // Create the user
    const newUser = new User({
      provider: 'local',
      email: DEFAULT_USER_EMAIL,
      emailVerified: true,  // Auto-verify for default user
      password: hashedPassword,
      username: DEFAULT_USER_EMAIL.split('@')[0],
      name: DEFAULT_USER_NAME,
      role: 'ADMIN',  // First user is admin
    });

    await newUser.save();

    console.log('======================================');
    console.log('✅ User created successfully!');
    console.log('======================================');
    console.log('Login credentials:');
    console.log(`  Email: ${DEFAULT_USER_EMAIL}`);
    console.log(`  Password: ${DEFAULT_USER_PASSWORD}`);
    console.log('======================================');

    await mongoose.connection.close();
    process.exit(0);

  } catch (error) {
    console.error('ERROR: Failed to create user');
    console.error(error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Wait a bit for MongoDB to be fully ready
setTimeout(() => {
  createDefaultUser();
}, 5000);
