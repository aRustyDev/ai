import mongoose from "mongoose";
const { Schema } = mongoose;

const datasourceSchema = new Schema({
  title: String, // String is shorthand for {type: String}
  author: String,
  body: String,
  comments: [{ body: String, date: Date }],
  date: { type: Date, default: Date.now },
  hidden: Boolean,
  meta: {
    votes: Number,
    favs: Number,
  },
});

// provider {
//  name,
//  model[],
//  resources[],
//  datasources[],
//  schema[config{}],
// }
// config{
//   type
//   name
//   description
//   required
//   default
//   validation
//   sensitive
// }
// owner
// camelcase
// snakecase
//
