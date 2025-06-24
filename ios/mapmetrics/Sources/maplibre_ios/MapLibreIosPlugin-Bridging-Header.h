#ifndef MapLibreIosPlugin_Bridging_Header_h
#define MapLibreIosPlugin_Bridging_Header_h

#import <Foundation/Foundation.h>

// Expose the Swift clustering method to C
#ifdef __cplusplus
extern "C" {
#endif

// Function to create a MLNShapeSource with clustering options
// Returns a pointer to the created MLNShapeSource object
void* createShapeSourceWithClustering(
    const char* identifier,
    const char* shape,
    const char* options
);

#ifdef __cplusplus
}
#endif

#endif /* MapLibreIosPlugin_Bridging_Header_h */ 