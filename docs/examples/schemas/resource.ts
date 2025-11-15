import mongoose from "mongoose";
// const schema = require('schm')
const { Schema } = mongoose;

const resourceSchema = new Schema({
  name: String, // String is shorthand for {type: String}
  capitalize: String,
  description: [{ body: String, date: Date }],
  private: Boolean,
});
