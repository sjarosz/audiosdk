import Foundation
import audiosdk

// Create an instance of the Greeter class from our SDK.
let greeter = Greeter()

// Call the method from the SDK.
let message = greeter.sayHello()

// Print the result to the console.
print(message)