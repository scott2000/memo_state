import { CustomType } from "../gleam.mjs";

export function refEquals(a, b) {
  return a === b;
}

export function shallowEquals(a, b) {
  if (a === b) {
    return true;
  }
  // For tuples (JS arrays), compare each element of the tuple separately
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) {
      return false;
    }
    for (let i = 0; i < a.length; i++) {
      if (!shallowEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  // Custom types with the same constructor and no properties should be considered equal
  if (a instanceof CustomType) {
    return a.constructor === b.constructor && isEmpty(a) && isEmpty(b);
  }
  return false;
}

function isEmpty(object) {
  for (const key in object) {
    if (Object.prototype.hasOwnProperty.call(object, key)) {
      return false;
    }
  }
  return true;
}
